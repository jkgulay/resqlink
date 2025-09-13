// Test file to verify WiFi Direct and Hotspot functionality
// Add this to your main.dart file or create a new test screen

import 'package:flutter/material.dart';
import 'lib/widgets/wifi_debug_panel.dart';
import 'lib/services/wifi_direct_service.dart';
import 'lib/services/hotspot_service.dart';

class TestWiFiDirectApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WiFi Direct Test',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
      ),
      home: WiFiTestHomePage(),
    );
  }
}

class WiFiTestHomePage extends StatefulWidget {
  @override
  _WiFiTestHomePageState createState() => _WiFiTestHomePageState();
}

class _WiFiTestHomePageState extends State<WiFiTestHomePage> {
  final WiFiDirectService _wifiDirectService = WiFiDirectService.instance;
  final HotspotService _hotspotService = HotspotService.instance;

  bool _isInitialized = false;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      setState(() {
        _statusMessage = 'Initializing WiFi services...';
      });

      await _wifiDirectService.initialize();
      await _hotspotService.initialize();

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Services initialized successfully!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('WiFi Direct & Hotspot Test'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isInitialized ? Colors.green.shade50 : Colors.orange.shade50,
                border: Border.all(
                  color: _isInitialized ? Colors.green : Colors.orange,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _isInitialized ? Colors.green.shade700 : Colors.orange.shade700,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: 24),

            if (_isInitialized) ...[
              Text(
                'Quick Test Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: () async {
                  setState(() {
                    _statusMessage = 'Testing permissions...';
                  });

                  final hasPermissions = await _wifiDirectService.checkAndRequestPermissions();
                  setState(() {
                    _statusMessage = hasPermissions
                      ? '✅ All permissions granted!'
                      : '❌ Some permissions missing. Check settings.';
                  });
                },
                icon: Icon(Icons.security),
                label: Text('Test Permissions'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),

              SizedBox(height: 8),

              ElevatedButton.icon(
                onPressed: () async {
                  setState(() {
                    _statusMessage = 'Starting WiFi Direct discovery...';
                  });

                  final success = await _wifiDirectService.startDiscovery();
                  setState(() {
                    _statusMessage = success
                      ? '✅ Discovery started! Look for peers in debug panel.'
                      : '❌ Discovery failed. Check permissions and WiFi.';
                  });
                },
                icon: Icon(Icons.search),
                label: Text('Start WiFi Direct Discovery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),

              SizedBox(height: 8),

              ElevatedButton.icon(
                onPressed: () async {
                  setState(() {
                    _statusMessage = 'Creating emergency hotspot...';
                  });

                  final success = await _hotspotService.createHotspot(
                    ssid: 'ResQLink_Test_${DateTime.now().millisecondsSinceEpoch}',
                    password: 'RESQLINK911',
                  );

                  setState(() {
                    if (success) {
                      _statusMessage = '✅ Hotspot created!\nSSID: ${_hotspotService.currentSSID}\nPassword: ${_hotspotService.currentPassword}';
                    } else {
                      _statusMessage = '❌ Hotspot creation failed. Check permissions.';
                    }
                  });
                },
                icon: Icon(Icons.wifi_tethering),
                label: Text('Create Test Hotspot'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),

              SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => WiFiDebugPanel()),
                  );
                },
                icon: Icon(Icons.deblur_outlined),
                label: Text('Open Debug Panel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),

              SizedBox(height: 24),

              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Testing Instructions:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('1. Test permissions first'),
                    Text('2. Start WiFi Direct discovery'),
                    Text('3. Try creating a hotspot'),
                    Text('4. Open debug panel for detailed logs'),
                    Text('5. Test with another device nearby'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Add this to your main.dart file to test:
/*
void main() {
  runApp(TestWiFiDirectApp());
}
*/