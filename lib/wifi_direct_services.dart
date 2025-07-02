import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';

class WiFiDirectService {
  static const String serviceId = "com.example.resqlink.emergency";
  static const Strategy strategy = Strategy.P2P_CLUSTER;

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

    // Request permissions
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
      bool success = await Nearby().startAdvertising(
        _localUserName!,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
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
      bool success = await Nearby().startDiscovery(
        serviceId,
        strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
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
      bool success = await Nearby().requestConnection(
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
      await Nearby().sendBytesPayload(
        endpointId,
        utf8.encode(
          jsonEncode({
            'type': 'message',
            'from': _localUserName,
            'message': message,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        ),
      );
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
      'from': _localUserName,
      'message': message,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    for (String endpointId in _connectedEndpoints.keys) {
      try {
        await Nearby().sendBytesPayload(
          endpointId,
          utf8.encode(jsonEncode(emergencyData)),
        );
      } catch (e) {
        print("Error broadcasting to $endpointId: $e");
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

  void _onEndpointLost(
    String endpointId,
    String endpointName,
    String serviceId,
  ) {
    _discoveredEndpoints.remove(endpointId);
    print("Lost endpoint: $endpointId ($endpointName)");
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

  void _onDisconnected(String endpointId) {
    _connectedEndpoints.remove(endpointId);
    onDeviceDisconnected?.call(endpointId);
    print("Disconnected from $endpointId");
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES) {
      try {
        String dataString = utf8.decode(payload.bytes!);
        Map<String, dynamic> data = jsonDecode(dataString);

        if (data['type'] == 'message' || data['type'] == 'emergency') {
          onMessageReceived?.call(endpointId, dataString);
        }
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

// WiFi Direct Page
class WiFiDirectPage extends StatefulWidget {
  const WiFiDirectPage({super.key});

  @override
  State<WiFiDirectPage> createState() => _WiFiDirectPageState();
}

class _WiFiDirectPageState extends State<WiFiDirectPage> {
  final WiFiDirectService _wifiDirectService = WiFiDirectService();
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
  }

  void _setupCallbacks() {
    _wifiDirectService.onDeviceFound = (endpointId, userName) {
      setState(() {});
      _showSnackBar("Found device: $userName");
    };

    _wifiDirectService.onDeviceConnected = (endpointId, userName) {
      setState(() {});
      _showSnackBar("Connected to: $userName");
    };

    _wifiDirectService.onDeviceDisconnected = (endpointId) {
      setState(() {});
      _showSnackBar("Device disconnected");
    };

    _wifiDirectService.onMessageReceived = (endpointId, messageData) {
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

  Future<void> _initialize() async {
    if (_userNameController.text.isEmpty) {
      _showSnackBar("Please enter your name");
      return;
    }

    bool success = await _wifiDirectService.initialize(
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
    await _wifiDirectService.startAdvertising();
    setState(() {
      _isAdvertising = true;
    });
  }

  Future<void> _startDiscovery() async {
    await _wifiDirectService.startDiscovery();
    setState(() {
      _isDiscovering = true;
    });
  }

  Future<void> _sendBroadcastMessage() async {
    if (_messageController.text.isEmpty) return;

    String message = _messageController.text;
    _messageController.clear();

    // Send to all connected devices
    for (String endpointId in _wifiDirectService.connectedDevices.keys) {
      await _wifiDirectService.sendMessage(endpointId, message);
    }

    setState(() {
      _messages.add("You: $message");
    });
  }

  Future<void> _sendEmergencyBroadcast() async {
    await _wifiDirectService.broadcastEmergency(
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
        title: const Text('WiFi Direct Chat'),
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
              ElevatedButton(
                onPressed: _initialize,
                child: const Text('Initialize WiFi Direct'),
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

              // Discovered Devices
              const Text(
                'Discovered Devices:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  itemCount: _wifiDirectService.discoveredDevices.length,
                  itemBuilder: (context, index) {
                    String endpointId = _wifiDirectService
                        .discoveredDevices
                        .keys
                        .elementAt(index);
                    String userName =
                        _wifiDirectService.discoveredDevices[endpointId]!;
                    bool isConnected = _wifiDirectService.connectedDevices
                        .containsKey(endpointId);

                    return ListTile(
                      leading: Icon(isConnected ? Icons.wifi : Icons.wifi_off),
                      title: Text(userName),
                      trailing: isConnected
                          ? const Text(
                              'Connected',
                              style: TextStyle(color: Colors.green),
                            )
                          : ElevatedButton(
                              onPressed: () => _wifiDirectService
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
                        child: ListView.builder(
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
                                  fontWeight: _messages[index].contains('🚨')
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
    _wifiDirectService.stop();
    _userNameController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}

// Nearby Devices Page
class NearbyDevicesPage extends StatefulWidget {
  const NearbyDevicesPage({super.key});

  @override
  State<NearbyDevicesPage> createState() => _NearbyDevicesPageState();
}

class _NearbyDevicesPageState extends State<NearbyDevicesPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Devices')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.bluetooth_searching,
              size: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const Text('Scanning for nearby devices...'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WiFiDirectPage()),
                );
              },
              child: const Text('Try WiFi Direct Instead'),
            ),
          ],
        ),
      ),
    );
  }
}

// Emergency Home Page
class EmergencyHomePage extends StatelessWidget {
  const EmergencyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
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
          const Text('Connect with nearby devices offline'),
          const SizedBox(height: 30),

          // WiFi Direct Button
          ElevatedButton.icon(
            icon: const Icon(Icons.wifi),
            label: const Text('WiFi Direct Chat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WiFiDirectPage()),
              );
            },
          ),

          const SizedBox(height: 16),

          // Original nearby devices button
          ElevatedButton.icon(
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Scan for Nearby Devices'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NearbyDevicesPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
