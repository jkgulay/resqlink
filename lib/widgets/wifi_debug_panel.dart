import 'package:flutter/material.dart';
import '../services/wifi_direct_service.dart';
import '../services/hotspot_service.dart';

class WiFiDebugPanel extends StatefulWidget {
  const WiFiDebugPanel({super.key});

  @override
  State<WiFiDebugPanel> createState() => _WiFiDebugPanelState();
}

class _WiFiDebugPanelState extends State<WiFiDebugPanel> {
  final WiFiDirectService _wifiDirectService = WiFiDirectService.instance;
  final HotspotService _hotspotService = HotspotService.instance;

  List<WiFiDirectPeer> _peers = [];
  List<ConnectedClient> _clients = [];
  WiFiDirectConnectionState _wifiDirectState = WiFiDirectConnectionState.disconnected;
  HotspotState _hotspotState = HotspotState.disabled;

  final List<String> _debugLogs = [];

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _addLog('🔧 Initializing WiFi services...');

    try {
      await _wifiDirectService.initialize();
      await _hotspotService.initialize();

      // Listen to streams
      _wifiDirectService.peersStream.listen((peers) {
        setState(() {
          _peers = peers;
        });
        _addLog('📡 Found ${peers.length} WiFi Direct peers');
      });

      _wifiDirectService.connectionStream.listen((state) {
        setState(() {
          _wifiDirectState = state;
        });
        _addLog('🔗 WiFi Direct state: ${state.name}');
      });

      _hotspotService.stateStream.listen((state) {
        setState(() {
          _hotspotState = state;
        });
        _addLog('📶 Hotspot state: ${state.name}');
      });

      _hotspotService.clientsStream.listen((clients) {
        setState(() {
          _clients = clients;
        });
        _addLog('👥 Connected clients: ${clients.length}');
      });

      _addLog('✅ Services initialized successfully');
    } catch (e) {
      _addLog('❌ Service initialization failed: $e');
    }
  }

  void _addLog(String message) {
    setState(() {
      _debugLogs.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_debugLogs.length > 50) {
        _debugLogs.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WiFi Debug Panel'),
        backgroundColor: Colors.deepOrange,
      ),
      body: DefaultTabController(
        length: 4,
        child: Column(
          children: [
            TabBar(
              labelColor: Colors.deepOrange,
              tabs: [
                Tab(text: 'Control', icon: Icon(Icons.settings)),
                Tab(text: 'Peers', icon: Icon(Icons.devices)),
                Tab(text: 'Hotspot', icon: Icon(Icons.wifi_tethering)),
                Tab(text: 'Logs', icon: Icon(Icons.list_alt)),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildControlTab(),
                  _buildPeersTab(),
                  _buildHotspotTab(),
                  _buildLogsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'WiFi Direct Controls',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),

          ElevatedButton(
            onPressed: () async {
              _addLog('🔐 Checking permissions...');
              final hasPermissions = await _wifiDirectService.checkAndRequestPermissions();
              _addLog('📋 Permissions result: $hasPermissions');
            },
            child: Text('Check Permissions'),
          ),

          SizedBox(height: 8),

          ElevatedButton(
            onPressed: _wifiDirectService.isDiscovering ? null : () async {
              _addLog('🔍 Starting WiFi Direct discovery...');
              final success = await _wifiDirectService.startDiscovery();
              _addLog('📡 Discovery result: $success');
            },
            child: Text(_wifiDirectService.isDiscovering ? 'Discovering...' : 'Start Discovery'),
          ),

          SizedBox(height: 8),

          ElevatedButton(
            onPressed: !_wifiDirectService.isDiscovering ? null : () async {
              _addLog('🛑 Stopping WiFi Direct discovery...');
              await _wifiDirectService.stopDiscovery();
            },
            child: Text('Stop Discovery'),
          ),

          SizedBox(height: 8),

          ElevatedButton(
            onPressed: () async {
              _addLog('👑 Creating WiFi Direct group...');
              final success = await _wifiDirectService.createGroup();
              _addLog('📡 Group creation result: $success');
            },
            child: Text('Create Group'),
          ),

          SizedBox(height: 8),

          ElevatedButton(
            onPressed: () async {
              _addLog('🗑️ Removing WiFi Direct group...');
              await _wifiDirectService.removeGroup();
            },
            child: Text('Remove Group'),
          ),

          SizedBox(height: 16),

          Text(
            'Status: ${_wifiDirectState.name}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPeersTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Discovered Peers (${_peers.length})',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),

          Expanded(
            child: _peers.isEmpty
              ? Center(child: Text('No peers found. Start discovery first.'))
              : ListView.builder(
                  itemCount: _peers.length,
                  itemBuilder: (context, index) {
                    final peer = _peers[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.device_hub, color: Colors.blue),
                        title: Text(peer.deviceName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Address: ${peer.deviceAddress}'),
                            Text('Type: ${peer.primaryDeviceType}'),
                            Text('Status: ${_getStatusText(peer.status)}'),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            _addLog('🔗 Connecting to ${peer.deviceName}...');
                            final success = await _wifiDirectService.connectToPeer(peer.deviceAddress);
                            _addLog('📡 Connection result: $success');
                          },
                          child: Text('Connect'),
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

  Widget _buildHotspotTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hotspot Controls',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),

          ElevatedButton(
            onPressed: _hotspotState == HotspotState.enabled ? null : () async {
              _addLog('📶 Creating hotspot...');
              final success = await _hotspotService.createHotspot();
              _addLog('🔥 Hotspot creation result: $success');
            },
            child: Text(_hotspotState == HotspotState.creating ? 'Creating...' : 'Create Hotspot'),
          ),

          SizedBox(height: 8),

          ElevatedButton(
            onPressed: _hotspotState != HotspotState.enabled ? null : () async {
              _addLog('🛑 Stopping hotspot...');
              await _hotspotService.stopHotspot();
            },
            child: Text('Stop Hotspot'),
          ),

          SizedBox(height: 16),

          if (_hotspotService.isEnabled) ...[
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hotspot Active', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  SizedBox(height: 8),
                  Text('SSID: ${_hotspotService.currentSSID ?? "Unknown"}'),
                  Text('Password: ${_hotspotService.currentPassword ?? "Unknown"}'),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],

          Text(
            'Connected Clients (${_clients.length})',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),

          Expanded(
            child: _clients.isEmpty
              ? Center(child: Text('No clients connected.'))
              : ListView.builder(
                  itemCount: _clients.length,
                  itemBuilder: (context, index) {
                    final client = _clients[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.phone_android, color: Colors.green),
                        title: Text(client.deviceName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('IP: ${client.ipAddress}'),
                            Text('MAC: ${client.macAddress}'),
                          ],
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

  Widget _buildLogsTab() {
    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Debug Logs (${_debugLogs.length})',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _debugLogs.clear();
                  });
                },
                child: Text('Clear'),
              ),
            ],
          ),
          SizedBox(height: 16),

          Expanded(
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _debugLogs.isEmpty
                ? Center(child: Text('No logs yet.'))
                : ListView.builder(
                    itemCount: _debugLogs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          _debugLogs[index],
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: _getLogColor(_debugLogs[index]),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(int status) {
    switch (status) {
      case 0: return 'Connected';
      case 1: return 'Invited';
      case 2: return 'Failed';
      case 3: return 'Available';
      case 4: return 'Unavailable';
      default: return 'Unknown ($status)';
    }
  }

  Color _getLogColor(String log) {
    if (log.contains('❌')) return Colors.red;
    if (log.contains('⚠️')) return Colors.orange;
    if (log.contains('✅')) return Colors.green;
    if (log.contains('🔧') || log.contains('🔍')) return Colors.blue;
    return Colors.black87;
  }

  @override
  void dispose() {
    super.dispose();
  }
}