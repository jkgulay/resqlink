import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'gps_page.dart';
import 'package:resqlink/settings_page.dart';
import 'package:resqlink/wifi_direct_wrapper.dart';
import 'package:resqlink/services/database_service.dart';
import 'package:resqlink/models/message_model.dart';

// WiFi Direct Service Class with Location Sharing
class WiFiDirectService with ChangeNotifier {
  final Map<String, List<Map<String, dynamic>>> messageHistory = {};
  static const String serviceId = "com.example.resqlink.emergency";
  static const Strategy strategy = Strategy.P2P_CLUSTER;
  final NearbyWrapper _nearbyWrapper = NearbyWrapper();

  void _addToHistory(String endpointId, Map<String, dynamic> data, bool isMe) {
    if (!messageHistory.containsKey(endpointId)) {
      messageHistory[endpointId] = [];
    }
    messageHistory[endpointId]!.add({...data, 'isMe': isMe});
    notifyListeners();
  }

  String? _localUserName;
  Map<String, String> _discoveredEndpoints = {};
  Map<String, String> _connectedEndpoints = {};

  // Callbacks
  Function(String endpointId, String userName)? onDeviceFound;
  Function(String endpointId, String userName)? onDeviceConnected;
  Function(String endpointId)? onDeviceDisconnected;
  Function(String endpointId, String message)? onMessageReceived;

  // Initialize WiFi Direct
  Future<bool> initialize(String userName) async {
    _localUserName = userName;
    await _requestPermissions();
    return true;
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();
  }

  // Start advertising (become discoverable)
  Future<void> startAdvertising() async {
    try {
      if (_localUserName == null) {
        print("Cannot start advertising without a username");
        return;
      }

      bool success = await _nearbyWrapper.startAdvertising(
        _localUserName!,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      if (success) {
        print("Started advertising as $_localUserName");
      }
    } catch (e) {
      print("Error starting advertising: $e");
    }
  }

  // Start discovery (find other devices)
  Future<void> startDiscovery() async {
    try {
      bool success = await _nearbyWrapper.startDiscovery(
        onEndpointFound: (endpointId, endpointName, serviceId) {
          _onEndpointFound(endpointId, endpointName, serviceId);
        },
        onEndpointLost: (endpointId) {
          _onEndpointLost(endpointId);
        },
      );

      if (success) {
        print("Started discovery");
      }
    } catch (e) {
      print("Error starting discovery: $e");
    }
  }

  // Connect to a discovered device
  Future<void> connectToDevice(String endpointId) async {
    try {
      if (_localUserName == null) {
        print("Cannot connect without a username");
        return;
      }

      bool success = await _nearbyWrapper.requestConnection(
        _localUserName!,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      if (success) {
        print("Connection requested to $endpointId");
      }
    } catch (e) {
      print("Error connecting to device: $e");
    }
  }

  // Send message to connected device
  Future<void> sendMessage(String endpointId, String message) async {
    try {
      final data = {
        'type': 'message',
        'from': _localUserName,
        'message': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      await _nearbyWrapper.sendBytesPayload(endpointId, bytes);
      _addToHistory(endpointId, data, true);

      // Save to database
      final messageModel = MessageModel(
        endpointId: endpointId,
        fromUser: _localUserName ?? 'Me',
        message: message,
        isMe: true,
        isEmergency: false,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        latitude: 0.0, // Add default latitude or get actual location
        longitude: 0.0, // Add default longitude or get actual location
      );

      await DatabaseService.insertMessage(messageModel);
    } catch (e) {
      print("Error sending message: $e");
    }
  }

  // Send location to connected device
  Future<void> sendLocation(String endpointId, LocationModel location) async {
    try {
      final data = {
        'type': 'location',
        'from': _localUserName,
        'message': 'Shared location: ${location.type.name}',
        'latitude': location.latitude,
        'longitude': location.longitude,
        'location_type': location.type.name,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'location_timestamp': location.timestamp.millisecondsSinceEpoch,
      };

      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      await _nearbyWrapper.sendBytesPayload(endpointId, bytes);

      // Add to history with location data
      _addToHistory(endpointId, {...data, 'isMe': true}, true);

      // Also save to database
      final messageModel = MessageModel(
        endpointId: endpointId,
        fromUser: _localUserName ?? 'Me',
        message: 'Shared location: ${location.type.name}',
        isMe: true,
        isEmergency:
            location.type == LocationType.emergency ||
            location.type == LocationType.sos,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        latitude: location.latitude,
        longitude: location.longitude,
      );
      await DatabaseService.insertMessage(messageModel);
    } catch (e) {
      print("Error sending location: $e");
    }
  }

  // Broadcast emergency message to all connected devices
  Future<void> broadcastEmergency(
    String message,
    double? latitude,
    double? longitude,
  ) async {
    final emergencyData = {
      'type': 'emergency',
      'priority': 1,
      'from': _localUserName,
      'message': message,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    for (String endpointId in _connectedEndpoints.keys) {
      for (int i = 0; i < 3; i++) {
        try {
          final bytes = Uint8List.fromList(
            utf8.encode(jsonEncode(emergencyData)),
          );
          await _nearbyWrapper.sendBytesPayload(endpointId, bytes);
          _addToHistory(endpointId, emergencyData, true);

          // Save to database
          // Option 1: Check if location is available before creating the message
          final messageModel = MessageModel(
            endpointId: endpointId,
            fromUser: _localUserName ?? 'Me',
            message: message,
            isMe: true,
            isEmergency: true,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            latitude: latitude ?? 0.0,
            longitude: longitude ?? 0.0,
          );

          await DatabaseService.insertMessage(messageModel);
          break;
        } catch (e) {
          if (i == 2) {
            print("Failed to send emergency to $endpointId after 3 attempts");
          }
        }
      }
    }
  }

  // Event handlers
  void _onEndpointFound(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    _discoveredEndpoints[endpointId] = endpointName;
    onDeviceFound?.call(endpointId, endpointName);
    print("Found endpoint: $endpointName ($endpointId)");
  }

  void _onEndpointLost(String endpointId) {
    String? endpointNameRemoved = _discoveredEndpoints.remove(endpointId);
    print(
      "Lost endpoint: $endpointId${endpointNameRemoved != null ? ' ($endpointNameRemoved)' : ''}",
    );

    if (_connectedEndpoints.containsKey(endpointId)) {
      _connectedEndpoints.remove(endpointId);
      onDeviceDisconnected?.call(endpointId);
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    print("Connection initiated with $endpointId");
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connectedEndpoints[endpointId] =
          _discoveredEndpoints[endpointId] ?? "Unknown";
      onDeviceConnected?.call(endpointId, _connectedEndpoints[endpointId]!);
      print("Connected to $endpointId");
    } else {
      print("Connection failed with $endpointId");
    }
  }

  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    onDeviceDisconnected?.call(endpointId);
    print("Disconnected from $endpointId");

    if (_discoveredEndpoints.containsKey(endpointId)) {
      Future.delayed(Duration(seconds: 2), () {
        connectToDevice(endpointId);
      });
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      try {
        String dataString = utf8.decode(payload.bytes!);
        Map<String, dynamic> data = jsonDecode(dataString);

        if (data['type'] == 'emergency') {
          triggerEmergencyFeedback();
        }

        _addToHistory(endpointId, data, false);
        onMessageReceived?.call(endpointId, dataString);

        // Save to database
        final messageModel = MessageModel(
          endpointId: endpointId,
          fromUser: data['from'] ?? 'Unknown',
          message: data['message'] ?? '',
          isMe: false,
          isEmergency: data['type'] == 'emergency',
          timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
          latitude: (data['latitude'] ?? 0.0).toDouble(),
          longitude: (data['longitude'] ?? 0.0).toDouble(),
        );
        DatabaseService.insertMessage(messageModel);
      } catch (e) {
        print("Error processing payload: $e");
      }
    }
  }

  Future<void> stop() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();
    _discoveredEndpoints.clear();
    _connectedEndpoints.clear();
  }

  Map<String, String> get discoveredDevices => Map.from(_discoveredEndpoints);
  Map<String, String> get connectedDevices => Map.from(_connectedEndpoints);
  String? get localUserName => _localUserName;
}

// Main Home Page with Navigation
class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;
  final WiFiDirectService _wifiDirectService = WiFiDirectService();
  LocationModel? _currentLocation;
  String? _userId = "user_${DateTime.now().millisecondsSinceEpoch}";

  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    pages = [
      EmergencyHomePage(
        wifiDirectService: _wifiDirectService,
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
          // Optionally show a snackbar or notification
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location updated: ${location.type.name}'),
              backgroundColor: location.type == LocationType.emergency
                  ? Colors.red
                  : Colors.green,
            ),
          );
        },
      ),
      MessagePage(
        wifiDirectService: _wifiDirectService,
        currentLocation: _currentLocation,
      ),
      SettingsPage(),
    ];
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
    _wifiDirectService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Update pages with current location when switching tabs
    if (selectedIndex == 2 && pages.length > 2) {
      pages[2] = MessagePage(
        wifiDirectService: _wifiDirectService,
        currentLocation: _currentLocation,
      );
    }

    final mainArea = ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: 200),
        child: pages[selectedIndex],
        layoutBuilder: (currentChild, _) => currentChild!,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/1.png', height: 30),
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
          if (_currentLocation != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Icon(
                  Icons.location_on,
                  color: _currentLocation!.type == LocationType.emergency
                      ? Colors.red
                      : Colors.green,
                ),
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

// Enhanced Emergency Home Page with WiFi Direct Integration
class EmergencyHomePage extends StatefulWidget {
  final WiFiDirectService wifiDirectService;
  final Function(LocationModel)? onLocationUpdate;

  const EmergencyHomePage({
    super.key,
    required this.wifiDirectService,
    this.onLocationUpdate,
  });

  @override
  State<EmergencyHomePage> createState() => _EmergencyHomePageState();
}

class _EmergencyHomePageState extends State<EmergencyHomePage> {
  LocationModel? _latestLocation;
  bool _isLoadingLocation = true;
  int _unsyncedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadLatestLocation();
    _checkUnsyncedLocations();
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
      final count = await LocationService.getUnsyncedCount();
      if (mounted) {
        setState(() {
          _unsyncedCount = count;
        });
      }
    } catch (e) {
      print('Error checking unsynced locations: $e');
    }
  }

  void _showQuickEmergencyDialog(BuildContext context) {
    final TextEditingController messageController = TextEditingController();

    if (_latestLocation != null) {
      messageController.text =
          'EMERGENCY! My last location: '
          'Lat: ${_latestLocation!.latitude.toStringAsFixed(6)}, '
          'Lon: ${_latestLocation!.longitude.toStringAsFixed(6)} '
          '(${_formatDateTime(_latestLocation!.timestamp)})';
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
              if (_latestLocation != null) {
                await widget.wifiDirectService.broadcastEmergency(
                  message,
                  _latestLocation!.latitude,
                  _latestLocation!.longitude,
                );
              } else {
                await widget.wifiDirectService.broadcastEmergency(
                  message,
                  null,
                  null,
                );
              }

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

  @override
  Widget build(BuildContext context) {
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
                'Emergency Contact Finder',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Connect with nearby devices offline',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // Location display section
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
                          valueColor: Colors.grey,
                        ),
                        _buildLocationRow(
                          Icons.map,
                          "Longitude",
                          _latestLocation!.longitude.toStringAsFixed(6),
                          valueColor: Colors.grey,
                        ),
                        _buildLocationRow(
                          Icons.access_time,
                          "Time",
                          _formatDateTime(_latestLocation!.timestamp),
                          valueColor: Colors.grey,
                        ),
                        _buildLocationRow(
                          Icons.category,
                          "Type",
                          _getLocationTypeLabel(_latestLocation!.type),
                          valueColor: _getLocationTypeColor(
                            _latestLocation!.type,
                          ),
                        ),
                        if (!_latestLocation!.synced)
                          _buildLocationRow(
                            Icons.cloud_off,
                            "Status",
                            "Not synced",
                            valueColor: Colors.orange,
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
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(Icons.location_off, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'No location data available',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.gps_fixed),
                          label: const Text('Open GPS Tracker'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GpsPage(
                                  userId:
                                      'user_${DateTime.now().millisecondsSinceEpoch}',
                                  onLocationShare: (location) {
                                    setState(() {
                                      _latestLocation = location;
                                    });
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
                  ),
                ),
                const SizedBox(height: 20),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.wifi),
                  label: const Text('WiFi Direct Emergency Chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WiFiDirectPage(
                          wifiDirectService: widget.wifiDirectService,
                          currentLocation: _latestLocation,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.emergency),
                  label: const Text('Quick Emergency Broadcast'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    _showQuickEmergencyDialog(context);
                  },
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Scan for Nearby Devices'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NearbyDevicesPage(
                          wifiDirectService: widget.wifiDirectService,
                          currentLocation: _latestLocation,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

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
                            'Connection Status',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'WiFi Direct allows you to connect directly with nearby devices without internet. Perfect for emergency situations.',
                        style: TextStyle(color: Colors.grey[600]),
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

  String _getLocationTypeLabel(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return 'Normal';
      case LocationType.emergency:
        return 'Emergency';
      case LocationType.sos:
        return 'SOS';
      case LocationType.safezone:
        return 'Safe Zone';
      case LocationType.hazard:
        return 'Hazard';
      case LocationType.evacuationPoint:
        return 'Evacuation Point';
      case LocationType.medicalAid:
        return 'Medical Aid';
      case LocationType.supplies:
        return 'Supplies';
    }
  }

  Color _getLocationTypeColor(LocationType type) {
    switch (type) {
      case LocationType.emergency:
      case LocationType.sos:
      case LocationType.hazard:
        return Colors.red;
      case LocationType.safezone:
      case LocationType.evacuationPoint:
        return Colors.green;
      case LocationType.medicalAid:
        return Colors.blue;
      case LocationType.supplies:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

// Enhanced WiFi Direct Page with Location
class WiFiDirectPage extends StatefulWidget {
  final WiFiDirectService wifiDirectService;
  final LocationModel? currentLocation;
  final bool autoEmergency;

  const WiFiDirectPage({
    super.key,
    required this.wifiDirectService,
    this.currentLocation,
    this.autoEmergency = false,
  });

  @override
  State<WiFiDirectPage> createState() => _WiFiDirectPageState();
}

class _WiFiDirectPageState extends State<WiFiDirectPage> {
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  bool _isInitialized = false;
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _setupCallbacks();

    if (widget.autoEmergency) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showEmergencySetup();
      });
    }
  }

  void _setupCallbacks() {
    widget.wifiDirectService.onDeviceFound = (endpointId, userName) {
      setState(() {});
      _showSnackBar("Found device: $userName");
    };

    widget.wifiDirectService.onDeviceConnected = (endpointId, userName) {
      setState(() {});
      _showSnackBar("Connected to: $userName");
    };

    widget.wifiDirectService.onDeviceDisconnected = (endpointId) {
      setState(() {});
      _showSnackBar("Device disconnected");
    };

    widget.wifiDirectService.onMessageReceived = (endpointId, messageData) {
      try {
        Map<String, dynamic> data = jsonDecode(messageData);
        String displayMessage = "${data['from']}: ${data['message']}";

        if (data['type'] == 'emergency') {
          displayMessage =
              "🚨 EMERGENCY from ${data['from']}: ${data['message']}";
        } else if (data['type'] == 'location') {
          displayMessage =
              "📍 ${data['from']} shared location: ${data['latitude']}, ${data['longitude']}";
        }

        setState(() {
          _messages.add(displayMessage);
        });
      } catch (e) {
        print("Error parsing message: $e");
      }
    };
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showEmergencySetup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('🚨 Emergency Mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your name to start emergency broadcasting:'),
              const SizedBox(height: 16),
              TextField(
                controller: _userNameController,
                decoration: const InputDecoration(
                  labelText: 'Your Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Start Emergency Mode',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _initializeEmergencyMode();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _initializeEmergencyMode() async {
    if (_userNameController.text.isEmpty) {
      _userNameController.text = "Emergency User";
    }

    await _initialize();
    if (_isInitialized) {
      await _startAdvertising();
      await _startDiscovery();
      await _sendEmergencyBroadcast();
    }
  }

  Future<void> _initialize() async {
    if (_userNameController.text.isEmpty) {
      _showSnackBar("Please enter your name");
      return;
    }

    bool success = await widget.wifiDirectService.initialize(
      _userNameController.text,
    );
    if (success) {
      setState(() {
        _isInitialized = true;
      });
      _showSnackBar("WiFi Direct initialized");
    }
  }

  Future<void> _startAdvertising() async {
    await widget.wifiDirectService.startAdvertising();
    setState(() {
      _isAdvertising = true;
    });
  }

  Future<void> _startDiscovery() async {
    await widget.wifiDirectService.startDiscovery();
    setState(() {
      _isDiscovering = true;
    });
  }

  Future<void> _sendBroadcastMessage() async {
    if (_messageController.text.isEmpty) return;

    String message = _messageController.text;
    _messageController.clear();

    for (String endpointId in widget.wifiDirectService.connectedDevices.keys) {
      await widget.wifiDirectService.sendMessage(endpointId, message);
    }

    setState(() {
      _messages.add("You: $message");
    });
  }

  Future<void> _sendEmergencyBroadcast() async {
    await widget.wifiDirectService.broadcastEmergency(
      "EMERGENCY ASSISTANCE NEEDED!",
      widget.currentLocation?.latitude,
      widget.currentLocation?.longitude,
    );

    setState(() {
      _messages.add("🚨 You: EMERGENCY BROADCAST SENT");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Direct Emergency Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning, color: Colors.red),
            onPressed: _isInitialized ? _sendEmergencyBroadcast : null,
            tooltip: 'Send Emergency Broadcast',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!_isInitialized) ...[
              TextField(
                controller: _userNameController,
                decoration: const InputDecoration(
                  labelText: 'Your Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _initialize,
                  child: const Text('Initialize WiFi Direct'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isAdvertising ? null : _startAdvertising,
                      child: Text(
                        _isAdvertising ? 'Advertising...' : 'Start Advertising',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isDiscovering ? null : _startDiscovery,
                      child: Text(
                        _isDiscovering ? 'Discovering...' : 'Start Discovery',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(
                        _isAdvertising && _isDiscovering
                            ? Icons.wifi
                            : Icons.wifi_off,
                        color: _isAdvertising && _isDiscovering
                            ? Colors.green
                            : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Discovered: ${widget.wifiDirectService.discoveredDevices.length} | '
                        'Connected: ${widget.wifiDirectService.connectedDevices.length}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Discovered Devices:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 120,
                child: widget.wifiDirectService.discoveredDevices.isEmpty
                    ? const Center(
                        child: Text(
                          'No devices found. Make sure both devices are scanning.',
                        ),
                      )
                    : ListView.builder(
                        itemCount:
                            widget.wifiDirectService.discoveredDevices.length,
                        itemBuilder: (context, index) {
                          String endpointId = widget
                              .wifiDirectService
                              .discoveredDevices
                              .keys
                              .elementAt(index);
                          String userName = widget
                              .wifiDirectService
                              .discoveredDevices[endpointId]!;
                          bool isConnected = widget
                              .wifiDirectService
                              .connectedDevices
                              .containsKey(endpointId);

                          return ListTile(
                            leading: Icon(
                              isConnected ? Icons.wifi : Icons.wifi_off,
                            ),
                            title: Text(userName),
                            trailing: isConnected
                                ? const Text(
                                    'Connected',
                                    style: TextStyle(color: Colors.green),
                                  )
                                : ElevatedButton(
                                    onPressed: () => widget.wifiDirectService
                                        .connectToDevice(endpointId),
                                    child: const Text('Connect'),
                                  ),
                          );
                        },
                      ),
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Messages:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _messages.isEmpty
                            ? const Center(child: Text('No messages yet'))
                            : ListView.builder(
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      _messages[index],
                                      style: TextStyle(
                                        color: _messages[index].contains('🚨')
                                            ? Colors.red
                                            : _messages[index].contains('📍')
                                            ? Colors.blue
                                            : null,
                                        fontWeight:
                                            _messages[index].contains('🚨')
                                            ? FontWeight.bold
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sendBroadcastMessage,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}

// Enhanced Nearby Devices Page with Location
class NearbyDevicesPage extends StatefulWidget {
  final WiFiDirectService wifiDirectService;
  final LocationModel? currentLocation;

  const NearbyDevicesPage({
    super.key,
    required this.wifiDirectService,
    this.currentLocation,
  });

  @override
  State<NearbyDevicesPage> createState() => _NearbyDevicesPageState();
}

class _NearbyDevicesPageState extends State<NearbyDevicesPage> {
  @override
  void initState() {
    super.initState();
    _setupCallbacks();
  }

  void _setupCallbacks() {
    widget.wifiDirectService.onDeviceFound = (endpointId, userName) {
      setState(() {});
    };

    widget.wifiDirectService.onDeviceConnected = (endpointId, userName) {
      setState(() {});
    };

    widget.wifiDirectService.onDeviceDisconnected = (endpointId) {
      setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Devices')),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi_tethering, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(
                        'WiFi Direct Status',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Discovered: ${widget.wifiDirectService.discoveredDevices.length} devices\n'
                    'Connected: ${widget.wifiDirectService.connectedDevices.length} devices',
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.wifi),
                    label: const Text('Open WiFi Direct Chat'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WiFiDirectPage(
                            wifiDirectService: widget.wifiDirectService,
                            currentLocation: widget.currentLocation,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: widget.wifiDirectService.discoveredDevices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.bluetooth_searching,
                          size: 100,
                          color: Colors.blue,
                        ),
                        const SizedBox(height: 20),
                        const Text('No devices found yet'),
                        const SizedBox(height: 10),
                        const Text(
                          'Start WiFi Direct to discover nearby devices',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount:
                        widget.wifiDirectService.discoveredDevices.length,
                    itemBuilder: (context, index) {
                      String endpointId = widget
                          .wifiDirectService
                          .discoveredDevices
                          .keys
                          .elementAt(index);
                      String userName = widget
                          .wifiDirectService
                          .discoveredDevices[endpointId]!;
                      bool isConnected = widget
                          .wifiDirectService
                          .connectedDevices
                          .containsKey(endpointId);

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isConnected
                                ? Colors.green
                                : Colors.grey,
                            child: Icon(
                              isConnected ? Icons.person : Icons.person_outline,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(userName),
                          subtitle: Text(
                            isConnected ? 'Connected' : 'Available',
                          ),
                          trailing: isConnected
                              ? ElevatedButton(
                                  child: const Text("Message"),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          userName: userName,
                                          endpointId: endpointId,
                                          wifiDirectService:
                                              widget.wifiDirectService,
                                          currentLocation:
                                              widget.currentLocation,
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : ElevatedButton(
                                  child: const Text("Connect"),
                                  onPressed: () {
                                    widget.wifiDirectService.connectToDevice(
                                      endpointId,
                                    );
                                  },
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Enhanced Chat Screen with Location Sharing
class ChatScreen extends StatefulWidget {
  final String userName;
  final String endpointId;
  final WiFiDirectService wifiDirectService;
  final LocationModel? currentLocation;

  const ChatScreen({
    super.key,
    required this.userName,
    required this.endpointId,
    required this.wifiDirectService,
    this.currentLocation,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _chatMessages = [];
  LocationModel? _currentLocation;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.currentLocation;
    _setupMessageListener();
    _loadLatestLocation();
  }

  Future<void> _loadLatestLocation() async {
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

  void _setupMessageListener() {
    widget.wifiDirectService.onMessageReceived = (endpointId, messageData) {
      if (endpointId == widget.endpointId) {
        try {
          Map<String, dynamic> data = jsonDecode(messageData);
          setState(() {
            _chatMessages.add({
              'message': data['message'],
              'from': data['from'],
              'type': data['type'],
              'timestamp': data['timestamp'],
              'latitude': data['latitude'],
              'longitude': data['longitude'],
              'location_type': data['location_type'],
              'isMe': false,
            });
          });
        } catch (e) {
          print("Error parsing message: $e");
        }
      }
    };
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    String message = _messageController.text.trim();
    _messageController.clear();

    setState(() {
      _chatMessages.add({
        'message': message,
        'from': widget.wifiDirectService.localUserName,
        'type': 'message',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isMe': true,
      });
    });

    await widget.wifiDirectService.sendMessage(widget.endpointId, message);
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

    setState(() {
      _chatMessages.add({
        'message': 'Shared location',
        'from': widget.wifiDirectService.localUserName,
        'type': 'location',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'latitude': _currentLocation!.latitude,
        'longitude': _currentLocation!.longitude,
        'location_type': _currentLocation!.type.name,
        'isMe': true,
      });
    });

    await widget.wifiDirectService.sendLocation(
      widget.endpointId,
      _currentLocation!,
    );
  }

  Future<void> _sendEmergencyMessage() async {
    setState(() {
      _chatMessages.add({
        'message': 'EMERGENCY ASSISTANCE NEEDED!',
        'from': widget.wifiDirectService.localUserName,
        'type': 'emergency',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'latitude': _currentLocation?.latitude,
        'longitude': _currentLocation?.longitude,
        'isMe': true,
      });
    });

    await widget.wifiDirectService.broadcastEmergency(
      'EMERGENCY ASSISTANCE NEEDED!',
      _currentLocation?.latitude,
      _currentLocation?.longitude,
    );
  }

  void _showLocationOnMap(double latitude, double longitude) {
    // Navigate to GPS page centered on the shared location
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GpsPage(
          userId: 'viewer',
          // You can pass the location to center the map
          // This would require modifying GpsPage to accept initial coordinates
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on),
            onPressed: _sendLocation,
            tooltip: 'Share Location',
          ),
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            onPressed: _sendEmergencyMessage,
            tooltip: 'Send Emergency',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color:
                widget.wifiDirectService.connectedDevices.containsKey(
                  widget.endpointId,
                )
                ? Colors.green.withAlpha((0.1 * 255).round())
                : Colors.red.withAlpha((0.1 * 255).round()),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.wifiDirectService.connectedDevices.containsKey(
                        widget.endpointId,
                      )
                      ? Icons.circle
                      : Icons.circle_outlined,
                  size: 12,
                  color:
                      widget.wifiDirectService.connectedDevices.containsKey(
                        widget.endpointId,
                      )
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.wifiDirectService.connectedDevices.containsKey(
                        widget.endpointId,
                      )
                      ? 'Connected'
                      : 'Disconnected',
                  style: TextStyle(
                    color:
                        widget.wifiDirectService.connectedDevices.containsKey(
                          widget.endpointId,
                        )
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _chatMessages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet. Start the conversation!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final message = _chatMessages[index];
                      final isMe = message['isMe'] as bool;
                      final isEmergency = message['type'] == 'emergency';
                      final isLocation = message['type'] == 'location';

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.7,
                          ),
                          decoration: BoxDecoration(
                            color: isEmergency
                                ? Colors.red
                                : isLocation
                                ? Colors.blue.shade700
                                : isMe
                                ? Colors.blue
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isEmergency)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.warning,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
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
                              if (isLocation) ...[
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.location_on,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
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
                                const SizedBox(height: 4),
                                if (message['latitude'] != null &&
                                    message['longitude'] != null)
                                  InkWell(
                                    onTap: () => _showLocationOnMap(
                                      message['latitude'],
                                      message['longitude'],
                                    ),
                                    child: Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(
                                          (0.2 * 255).round(),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.map,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                          SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'Lat: ${message['latitude'].toStringAsFixed(4)}, '
                                              'Lon: ${message['longitude'].toStringAsFixed(4)}',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ] else
                                Text(
                                  message['message'],
                                  style: TextStyle(
                                    color: isEmergency || isMe || isLocation
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: isEmergency
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTimestamp(message['timestamp']),
                                style: TextStyle(
                                  color: isEmergency || isMe || isLocation
                                      ? Colors.white70
                                      : Colors.black54,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.location_on),
                  onPressed: _currentLocation != null ? _sendLocation : null,
                  color: _currentLocation != null ? Colors.blue : Colors.grey,
                  tooltip: 'Share Location',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}

// Helper function for emergency feedback
void triggerEmergencyFeedback() {
  // This would trigger vibration and sound alerts
  // Implementation depends on platform-specific packages
  print("EMERGENCY ALERT TRIGGERED!");
}

// Update MessagePage to support location
class MessagePage extends StatelessWidget {
  final WiFiDirectService wifiDirectService;
  final LocationModel? currentLocation;

  const MessagePage({
    super.key,
    required this.wifiDirectService,
    this.currentLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.message, size: 80, color: Colors.blue),
          SizedBox(height: 20),
          Text(
            'Messages',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          ElevatedButton.icon(
            icon: Icon(Icons.chat),
            label: Text('Open WiFi Direct Chat'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WiFiDirectPage(
                    wifiDirectService: wifiDirectService,
                    currentLocation: currentLocation,
                  ),
                ),
              );
            },
          ),
          if (currentLocation != null) ...[
            SizedBox(height: 16),
            Card(
              margin: EdgeInsets.symmetric(horizontal: 32),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: currentLocation!.type == LocationType.emergency
                          ? Colors.red
                          : Colors.green,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Current Location Available',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Ready to share in chats',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum Menu { itemOne, itemTwo, itemThree }
