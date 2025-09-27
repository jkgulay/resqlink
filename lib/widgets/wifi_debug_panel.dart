import 'package:flutter/material.dart';
import '../services/p2p/wifi_direct_service.dart';

class WiFiDebugPanel extends StatefulWidget {
  const WiFiDebugPanel({super.key});

  @override
  State<WiFiDebugPanel> createState() => _WiFiDebugPanelState();
}

class _WiFiDebugPanelState extends State<WiFiDebugPanel> {
  final WiFiDirectService _wifiDirectService = WiFiDirectService.instance;

  List<WiFiDirectPeer> _peers = [];
  WiFiDirectConnectionState _wifiDirectState =
      WiFiDirectConnectionState.disconnected;

  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeDebugPanel();
  }

  void _initializeDebugPanel() {
    _addLog('🔧 WiFi Debug Panel initialized (WiFi Direct only)');

    // Listen to WiFi Direct state changes
    _wifiDirectService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _peers = _wifiDirectService.discoveredPeers;
          _wifiDirectState = _wifiDirectService.connectionState;
        });
        _addLog('📡 WiFi Direct state updated: $_wifiDirectState');
      }
    });

    // Initial state
    setState(() {
      _peers = _wifiDirectService.discoveredPeers;
      _wifiDirectState = _wifiDirectService.connectionState;
    });
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toLocal().toString().substring(11, 19);
    setState(() {
      _logs.add('[$timestamp] $message');
    });
    // Auto-scroll to bottom
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WiFi Direct Debug Panel'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WiFi Direct Status
            _buildStatusCard(
              'WiFi Direct Status',
              _getWiFiDirectStatusText(),
              _wifiDirectState == WiFiDirectConnectionState.connected
                  ? Colors.green
                  : Colors.orange,
            ),

            SizedBox(height: 16),

            // WiFi Direct Controls
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WiFi Direct Controls',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),

                    ElevatedButton(
                      onPressed: () async {
                        _addLog('🔍 Starting WiFi Direct discovery...');
                        await _wifiDirectService.startDiscovery();
                        _addLog('✅ WiFi Direct discovery started');
                      },
                      child: Text('Start Discovery'),
                    ),

                    SizedBox(height: 8),

                    ElevatedButton(
                      onPressed: () async {
                        _addLog('🛑 Stopping WiFi Direct discovery...');
                        await _wifiDirectService.stopDiscovery();
                        _addLog('✅ WiFi Direct discovery stopped');
                      },
                      child: Text('Stop Discovery'),
                    ),

                    SizedBox(height: 8),

                    ElevatedButton(
                      onPressed: () async {
                        _addLog('🔄 Refreshing WiFi Direct peers...');
                        setState(() {
                          _peers = _wifiDirectService.discoveredPeers;
                        });
                        _addLog('✅ Peers refreshed (${_peers.length} found)');
                      },
                      child: Text('Refresh Peers'),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Discovered Peers
            if (_peers.isNotEmpty) _buildPeersList(),

            SizedBox(height: 16),

            // Debug Logs
            _buildLogsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(String title, String status, Color color) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color),
              ),
              child: Text(
                status,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeersList() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Discovered WiFi Direct Peers (${_peers.length})',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ..._peers.map(
              (peer) => Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.devices, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.deviceName,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            peer.deviceAddress,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        _addLog('🔗 Connecting to ${peer.deviceName}...');
                        await _wifiDirectService.connectToPeer(
                          peer.deviceAddress,
                        );
                        _addLog('✅ Connection initiated to ${peer.deviceName}');
                      },
                      child: Text('Connect'),
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

  Widget _buildLogsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Debug Logs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[50],
              ),
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(8),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _logs[index],
                      style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _logs.clear();
                });
                _addLog('🧹 Logs cleared');
              },
              child: Text('Clear Logs'),
            ),
          ],
        ),
      ),
    );
  }

  String _getWiFiDirectStatusText() {
    switch (_wifiDirectState) {
      case WiFiDirectConnectionState.connected:
        return 'Connected';
      case WiFiDirectConnectionState.connecting:
        return 'Connecting';
      case WiFiDirectConnectionState.disconnected:
        return 'Disconnected';
      case WiFiDirectConnectionState.discovering:
        return 'Discovering';
      case WiFiDirectConnectionState.failed:
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
