import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'message_page.dart';
import 'dart:typed_data';
import 'gps_page.dart';
import 'package:resqlink/settings_page.dart';
import 'package:resqlink/wifi_direct_wrapper.dart';

// WiFi Direct Service Class
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
    notifyListeners(); // This will now work
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
      // Ensure _localUserName is not null
      if (_localUserName == null) {
        print("Cannot start advertising without a username");
        return;
      }

      bool success = await _nearbyWrapper.startAdvertising(
        _localUserName!, // Use ! to assert non-null
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

  // Update startDiscovery
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

      // Convert to Uint8List
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));

      await _nearbyWrapper.sendBytesPayload(endpointId, bytes);
      _addToHistory(endpointId, data, true);
    } catch (e) {
      print("Error sending message: $e");
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
      'priority': 1, // Highest priority
      'from': _localUserName,
      'message': message,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    // Send to all connected devices with retries
    for (String endpointId in _connectedEndpoints.keys) {
      for (int i = 0; i < 3; i++) {
        try {
          // Convert to Uint8List
          final bytes = Uint8List.fromList(
            utf8.encode(jsonEncode(emergencyData)),
          );
          await _nearbyWrapper.sendBytesPayload(endpointId, bytes);
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

    // Also remove from connected endpoints if present
    if (_connectedEndpoints.containsKey(endpointId)) {
      _connectedEndpoints.remove(endpointId);
      onDeviceDisconnected?.call(endpointId);
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    print("Connection initiated with $endpointId");
    // Auto-accept connections for emergency scenarios
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

  // Add automatic reconnection logic
  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    onDeviceDisconnected?.call(endpointId);
    print("Disconnected from $endpointId");

    // Attempt to reconnect
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
        _addToHistory(endpointId, data, false);
      } catch (e) {
        print("Error processing payload: $e");
      }
    }
  }

  // Stop all operations
  Future<void> stop() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();
    _discoveredEndpoints.clear();
    _connectedEndpoints.clear();
  }

  // Getters
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

  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      EmergencyHomePage(wifiDirectService: _wifiDirectService),
      GpsPage(),
      MessagePage(wifiDirectService: _wifiDirectService),
      SettingsPage(),
    ];
  }

  @override
  void dispose() {
    _wifiDirectService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: CircleAvatar(child: ProfileIcon()),
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
class EmergencyHomePage extends StatelessWidget {
  final WiFiDirectService wifiDirectService;

  const EmergencyHomePage({super.key, required this.wifiDirectService});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
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

            // WiFi Direct Chat Button (Primary)
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
                      builder: (_) =>
                          WiFiDirectPage(wifiDirectService: wifiDirectService),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Quick Emergency Broadcast Button
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

            // Scan for Devices Button (Secondary)
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
                        wifiDirectService: wifiDirectService,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Status Card
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
    );
  }

  void _showQuickEmergencyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Emergency Broadcast'),
          content: const Text(
            'This will send an emergency message to all nearby connected devices. Continue?',
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Send Emergency',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to WiFi Direct page and trigger emergency
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WiFiDirectPage(
                      wifiDirectService: wifiDirectService,
                      autoEmergency: true,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// Enhanced WiFi Direct Page
class WiFiDirectPage extends StatefulWidget {
  final WiFiDirectService wifiDirectService;
  final bool autoEmergency;

  const WiFiDirectPage({
    super.key,
    required this.wifiDirectService,
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

    // If auto emergency is triggered, show emergency setup
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
      null, // Add GPS coordinates if available
      null,
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
            // Initialization Section
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
              // Control Section
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

              // Connection Status
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

              // Discovered Devices
              const Text(
                'Discovered Devices:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 120,
                child: widget.wifiDirectService.discoveredDevices.isEmpty
                    ? const Center(
                        child: Text(
                          'No devices found. Make sure both devices are scanning and advertising.',
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

              // Messages Section
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

              // Message Input
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

// Enhanced Nearby Devices Page
class NearbyDevicesPage extends StatefulWidget {
  final WiFiDirectService wifiDirectService;

  const NearbyDevicesPage({super.key, required this.wifiDirectService});

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
          // Status Card
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

          // Action Buttons
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

          // Devices List
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
                          'Start WiFi Direct to discover nearby emergency devices',
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

// Enhanced Chat Screen for individual conversations
class ChatScreen extends StatefulWidget {
  final String userName;
  final String endpointId;
  final WiFiDirectService wifiDirectService;

  const ChatScreen({
    super.key,
    required this.userName,
    required this.endpointId,
    required this.wifiDirectService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    _setupMessageListener();
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

    // Add to local chat
    setState(() {
      _chatMessages.add({
        'message': message,
        'from': widget.wifiDirectService.localUserName,
        'type': 'message',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isMe': true,
      });
    });

    // Send via WiFi Direct
    await widget.wifiDirectService.sendMessage(widget.endpointId, message);
  }

  Future<void> _sendEmergencyMessage() async {
    // Add to local chat
    setState(() {
      _chatMessages.add({
        'message': 'EMERGENCY ASSISTANCE NEEDED!',
        'from': widget.wifiDirectService.localUserName,
        'type': 'emergency',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isMe': true,
      });
    });

    // Send emergency broadcast
    await widget.wifiDirectService.broadcastEmergency(
      'EMERGENCY ASSISTANCE NEEDED!',
      null,
      null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            onPressed: _sendEmergencyMessage,
            tooltip: 'Send Emergency',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color:
                widget.wifiDirectService.connectedDevices.containsKey(
                  widget.endpointId,
                )
                ? Colors.green.withValues()
                : Colors.red.withValues(),
            child: Text(
              widget.wifiDirectService.connectedDevices.containsKey(
                    widget.endpointId,
                  )
                  ? '🟢 Connected to ${widget.userName}'
                  : '🔴 Disconnected from ${widget.userName}',
              textAlign: TextAlign.center,
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
          ),

          // Messages
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
                              Text(
                                message['message'],
                                style: TextStyle(
                                  color: isEmergency || isMe
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
                                  color: isEmergency || isMe
                                      ? Colors.white70
                                      : Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Message Input
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

// Profile Icon Component
class ProfileIcon extends StatelessWidget {
  const ProfileIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Menu>(
      icon: const Icon(Icons.person),
      offset: const Offset(0, 40),
      onSelected: (Menu item) {
        // Handle menu selections
        switch (item) {
          case Menu.itemOne:
            // Handle Account
            break;
          case Menu.itemTwo:
            // Handle Settings
            break;
          case Menu.itemThree:
            // Handle Sign Out
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Menu>>[
        const PopupMenuItem<Menu>(value: Menu.itemOne, child: Text('Account')),
        const PopupMenuItem<Menu>(value: Menu.itemTwo, child: Text('Settings')),
        const PopupMenuItem<Menu>(
          value: Menu.itemThree,
          child: Text('Sign Out'),
        ),
      ],
    );
  }
}

enum Menu { itemOne, itemTwo, itemThree }
