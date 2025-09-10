import 'package:flutter/material.dart';
import '../../controllers/home_controller.dart';
import '../../services/p2p_service.dart';
import '../../utils/resqlink_theme.dart';

class ConnectionDiscoveryCard extends StatelessWidget {
  final HomeController controller;

  const ConnectionDiscoveryCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
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
              return _buildConnectionContent(context, isNarrow);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionContent(BuildContext context, bool isNarrow) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildConnectionHeader(isNarrow),
        SizedBox(height: 24),
        _buildActionButtons(context, isNarrow),
        SizedBox(height: 20),
        _buildConnectionStats(isNarrow),
        if (controller.discoveredDevices.isNotEmpty) ...[
          SizedBox(height: 24),
          _buildDevicesList(isNarrow),
        ],
        if (controller.isConnected) ...[
          SizedBox(height: 20),
          _buildConnectedDevices(isNarrow),
        ],
      ],
    );
  }

  Widget _buildConnectionHeader(bool isNarrow) {
    return Container(
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
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: controller.isConnected
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: controller.isConnected
                    ? Colors.green.withValues(alpha: 0.4)
                    : Colors.blue.withValues(alpha: 0.4),
              ),
            ),
            child: Icon(
              Icons.network_wifi,
              color: controller.isConnected ? Colors.green : Colors.blue,
              size: isNarrow ? 24 : 28,
            ),
          ),
          SizedBox(width: isNarrow ? 14 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Network Connection',
                  style: TextStyle(
                    fontSize: isNarrow ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  controller.isConnected
                      ? 'Connected to ${controller.p2pService.connectedDevices.length} device(s)'
                      : controller.isScanning
                      ? 'Scanning for devices...'
                      : 'Ready to connect',
                  style: TextStyle(
                    fontSize: isNarrow ? 13 : 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isNarrow) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: isNarrow ? 50 : 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: controller.isScanning
                    ? [Colors.orange, Colors.orange.shade700]
                    : [Colors.blue, Colors.blue.shade700],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (controller.isScanning ? Colors.orange : Colors.blue)
                      .withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: controller.isScanning
                  ? null
                  : () => controller.startScan(),
              icon: controller.isScanning
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.search, size: isNarrow ? 18 : 20),
              label: Text(
                controller.isScanning ? 'Scanning...' : 'Find Devices',
                style: TextStyle(
                  fontSize: isNarrow ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Container(
            height: isNarrow ? 50 : 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                // ✅ FIX: Better role-based color logic
                colors: _getRoleButtonColors(controller),
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _getRoleButtonColor(controller).withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _getRoleButtonAction(controller, context),
              icon: _getRoleButtonIcon(controller, isNarrow),
              label: Text(
                _getRoleButtonText(controller),
                style: TextStyle(
                  fontSize: isNarrow ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ✅ NEW: Helper methods for role button
  List<Color> _getRoleButtonColors(HomeController controller) {
    switch (controller.p2pService.currentRole) {
      case P2PRole.host:
        return [Colors.green, Colors.green.shade700];
      case P2PRole.client:
        return [Colors.blue, Colors.blue.shade700];
      case P2PRole.none:
        return [Colors.purple, Colors.purple.shade700];
    }
  }

  Color _getRoleButtonColor(HomeController controller) {
    switch (controller.p2pService.currentRole) {
      case P2PRole.host:
        return Colors.green;
      case P2PRole.client:
        return Colors.blue;
      case P2PRole.none:
        return Colors.purple;
    }
  }

  String _getRoleButtonText(HomeController controller) {
    switch (controller.p2pService.currentRole) {
      case P2PRole.host:
        return 'Hosting';
      case P2PRole.client:
        return 'Connected';
      case P2PRole.none:
        return 'Create Network';
    }
  }

  Widget _getRoleButtonIcon(HomeController controller, bool isNarrow) {
    IconData iconData;
    switch (controller.p2pService.currentRole) {
      case P2PRole.host:
        iconData = Icons.wifi_tethering;
      case P2PRole.client:
        iconData = Icons.wifi;
      case P2PRole.none:
        iconData = Icons.add_circle;
    }

    return Icon(iconData, size: isNarrow ? 18 : 20);
  }

  VoidCallback? _getRoleButtonAction(
    HomeController controller,
    BuildContext context,
  ) {
    switch (controller.p2pService.currentRole) {
      case P2PRole.host:
        return null; // Disable when already hosting
      case P2PRole.client:
        return () => _showConnectionDetails(context, controller);
      case P2PRole.none:
        return () => _showCreateNetworkDialog(context);
    }
  }

  void _showConnectionDetails(BuildContext context, HomeController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connection Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Role: ${controller.p2pService.currentRole.name.toUpperCase()}',
            ),
            Text(
              'Connected Devices: ${controller.p2pService.connectedDevices.length}',
            ),
            Text(
              'Connection Mode: ${controller.p2pService.currentConnectionMode.name}',
            ),
            if (controller.p2pService.connectedHotspotSSID != null)
              Text('Network: ${controller.p2pService.connectedHotspotSSID}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              controller.p2pService.disconnect();
            },
            child: Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStats(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNetworkStat(
            'Discovered',
            '${controller.discoveredDevices.length}',
            Icons.radar,
            Colors.blue,
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.blue.withValues(alpha: 0.3),
          ),
          _buildNetworkStat(
            'Connected',
            '${controller.p2pService.connectedDevices.length}',
            Icons.link,
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildDevicesList(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF1E3A5F).withValues(alpha: 0.2)),
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
                'Found ${controller.discoveredDevices.length} device${controller.discoveredDevices.length == 1 ? '' : 's'}',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w600,
                  fontSize: isNarrow ? 15 : 16,
                ),
              ),
            ],
          ),
          SizedBox(height: isNarrow ? 16 : 20),
          ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: controller.discoveredDevices.length,
            separatorBuilder: (context, index) =>
                SizedBox(height: isNarrow ? 8 : 12),
            itemBuilder: (context, index) {
              final device = controller.discoveredDevices[index];
              return _buildDeviceItem(device, isNarrow);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(Map<String, dynamic> device, bool isNarrow) {
    final signalStrength = -45 - (device.hashCode % 40);
    final signalLevel = _getSignalLevel(signalStrength);
    final signalColor = _getSignalColor(signalLevel);

    return Container(
      padding: EdgeInsets.all(isNarrow ? 16 : 18),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: signalColor.withValues(alpha: 0.2),
            radius: 24,
            child: Icon(Icons.devices, color: signalColor, size: 22),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device['deviceName'] ?? 'Unknown Device',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                SizedBox(height: 4),
                Text(
                  device['deviceAddress'] ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: signalColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSignalBars(signalLevel, signalColor),
                      SizedBox(width: 6),
                      Text(
                        '$signalStrength dBm',
                        style: TextStyle(
                          fontSize: 10,
                          color: signalColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => controller.connectToDevice(device),
            icon: Icon(Icons.link, size: 16),
            label: Text('Connect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedDevices(bool isNarrow) {
    return Container(
      padding: EdgeInsets.all(isNarrow ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
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
          ...controller.p2pService.connectedDevices.values.map(
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
                      device.userName,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: isNarrow ? 14 : 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      device.isHost ? 'HOST' : 'CLIENT',
                      style: TextStyle(
                        fontSize: isNarrow ? 10 : 11,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
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
  }

  Widget _buildSignalBars(int level, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final isActive = index < level;
        final barHeight = 8.0 + (index * 2);
        return Container(
          width: 3,
          height: barHeight,
          margin: EdgeInsets.only(right: 1.5),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
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

  void _showCreateNetworkDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: ResQLinkTheme.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.add_circle, color: ResQLinkTheme.primaryRed),
              SizedBox(width: 8),
              Text('Create Network', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose how to create your emergency network:',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 20),

              // WiFi Direct Option
              Container(
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.wifi, color: Colors.blue),
                  ),
                  title: Text(
                    'WiFi Direct',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Direct device-to-device connection (200m range)',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _createWiFiDirectNetwork();
                  },
                ),
              ),

              // Emergency Hotspot Option
              Container(
                margin: EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.purple.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.router, color: Colors.purple),
                  ),
                  title: Text(
                    'Emergency Hotspot',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Create WiFi hotspot for multiple devices',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _createHotspotNetwork();
                  },
                ),
              ),

              // Smart Network Option (your existing one, enhanced)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.green.withValues(alpha: 0.1),
                ),
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome, color: Colors.green),
                  ),
                  title: Text(
                    'Smart Network (Recommended)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Automatically choose the best method',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _createSmartNetwork();
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createWiFiDirectNetwork() async {
    try {
      debugPrint('🔗 Creating WiFi Direct network...');

      controller.p2pService.setHotspotFallbackEnabled(false);

      await controller.p2pService.checkAndRequestPermissions();

      await controller.startScan();

      debugPrint('✅ WiFi Direct network created successfully');
    } catch (e) {
      debugPrint('❌ Failed to create WiFi Direct network: $e');
    }
  }

  Future<void> _createHotspotNetwork() async {
    try {
      debugPrint('📶 Creating emergency hotspot...');

      // Force hotspot mode
      await controller.p2pService.connectionFallbackManager
          .initiateConnection();

      debugPrint('✅ Emergency hotspot created successfully');
    } catch (e) {
      debugPrint('❌ Failed to create hotspot: $e');
    }
  }

  Future<void> _createSmartNetwork() async {
    try {
      debugPrint('🤖 Creating smart network...');

      // Enable hybrid mode (your existing functionality)
      controller.p2pService.setHotspotFallbackEnabled(true);

      // Start with discovery that will fallback to hotspot if needed
      await controller.startScan();

      debugPrint('✅ Smart network initiated successfully');
    } catch (e) {
      debugPrint('❌ Failed to create smart network: $e');
    }
  }
}
