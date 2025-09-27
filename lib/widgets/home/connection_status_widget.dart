import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:resqlink/models/device_model.dart';
import '../../services/p2p/p2p_main_service.dart';

class EnhancedConnectionWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<P2PConnectionService>(
      builder: (context, p2pService, child) {
        return Card(
          margin: EdgeInsets.all(16),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionStatus(p2pService),
                SizedBox(height: 16),
                _buildNetworkActions(context, p2pService),
                SizedBox(height: 16),
                _buildAvailableNetworks(context, p2pService),
                SizedBox(height: 16),
                _buildDiscoveredDevices(p2pService),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionStatus(P2PConnectionService service) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connection Status',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Rajdhani',
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Icon(
              service.isConnected ? Icons.wifi : Icons.wifi_off,
              color: service.isConnected ? Colors.green : Colors.red,
            ),
            SizedBox(width: 8),
            Text(
              service.isConnected
                  ? 'Connected (${service.currentConnectionMode.name})'
                  : 'Disconnected',
              style: TextStyle(fontFamily: 'Inter'),
            ),
          ],
        ),
        
        if (service.emergencyMode) ...[
          SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.emergency, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Emergency Mode Active',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildNetworkActions(
    BuildContext context,
    P2PConnectionService service,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Network Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'Rajdhani',
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: service.isDiscovering
                  ? null
                  : () => service.discoverDevices(force: true),
              icon: service.isDiscovering
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.search),
              label: Text(
                service.isDiscovering ? 'Discovering...' : 'Discover',
              ),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
            ElevatedButton.icon(
              onPressed: () => service.emergencyMode = !service.emergencyMode,
              icon: Icon(
                service.emergencyMode ? Icons.emergency_share : Icons.emergency,
              ),
              label: Text(
                service.emergencyMode ? 'Exit Emergency' : 'Emergency Mode',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: service.emergencyMode
                    ? Colors.orange
                    : Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvailableNetworks(
    BuildContext context,
    P2PConnectionService service,
  ) {
    if (service.availableNetworks.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Available ResQLink Networks',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Rajdhani',
              ),
            ),
            SizedBox(width: 8),
            Text(
              '(${service.availableNetworks.length})',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ListView.builder(
            itemCount: service.availableNetworks.length,
            itemBuilder: (context, index) {
              final network = service.availableNetworks[index];
              return Card(
                margin: EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    Icons.wifi,
                    color: _getSignalColor(network['level'] as int?),
                  ),
                  title: Text(
                    network['ssid'] as String? ?? 'Unknown Network',
                    style: TextStyle(fontFamily: 'Inter'),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signal: ${network['level'] ?? 0}dBm | ${network['frequency'] ?? 0}MHz',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12,
                        ),
                      ),
                      if ((network['capabilities'] as String?)?.isNotEmpty == true)
                        Text(
                          'Security: ${network['capabilities'] ?? 'Open'}',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    onPressed: null, // Hotspot connection removed
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: Text('Connect'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoveredDevices(P2PConnectionService service) {
    // ✅ UPDATE: Use DeviceModel consistently
    final devices =
        service.discoveredResQLinkDevices; // Now returns List<DeviceModel>
    final connectedDevices = service.connectedDevices;

    if (devices.isEmpty && connectedDevices.isEmpty) return SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Discovered Devices',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Rajdhani',
              ),
            ),
            SizedBox(width: 8),
            Text(
              '(${devices.length + connectedDevices.length})',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
        SizedBox(height: 8),

        // Connected Devices
        if (connectedDevices.isNotEmpty) ...[
          Text(
            'Connected:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.green,
              fontFamily: 'Inter',
            ),
          ),
          ...connectedDevices.values.map(
            (device) => Card(
              margin: EdgeInsets.only(bottom: 4),
              color: Colors.green.withValues(alpha: 0.1),
              child: ListTile(
                leading: Icon(Icons.devices, color: Colors.green),
                title: Text(
                  // ✅ FIXED: Now using DeviceModel.userName correctly
                  device.userName.isNotEmpty
                      ? device.userName
                      : device.deviceId,
                  style: TextStyle(fontFamily: 'Inter'),
                ),
                subtitle: Text(
                  'Role: ${device.isHost ? "Host" : "Client"} | ID: ${device.deviceId}',
                  style: TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 12),
                    SizedBox(width: 8),
                    Text(
                      _formatTime(device.lastSeen),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 8),
        ],

        // Discovered Devices
        if (devices.isNotEmpty) ...[
          Text(
            'Available:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              fontFamily: 'Inter',
            ),
          ),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];
                return Card(
                  margin: EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    leading: Icon(Icons.devices_other, color: Colors.blue),
                    title: Text(
                      // ✅ FIXED: Now using DeviceModel.userName correctly
                      device.userName.isNotEmpty
                          ? device.userName
                          : device.deviceId,
                      style: TextStyle(fontFamily: 'Inter'),
                    ),
                    subtitle: Text(
                      'ID: ${device.deviceId} | Last seen: ${_formatTime(device.lastSeen)}',
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          color: device.isOnline
                              ? Colors.green
                              : _isRecentlySeen(device.lastSeen)
                              ? Colors.orange
                              : Colors.grey,
                          size: 12,
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _connectToDevice(service, device),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size(60, 28),
                          ),
                          child: Text(
                            'Connect',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // ✅ ADD: Method to connect to a discovered device
  void _connectToDevice(P2PConnectionService service, DeviceModel device) {
    // Convert DeviceModel to the format expected by connectToDevice
    final deviceMap = {
      'deviceId': device.deviceId,
      'deviceAddress': device.deviceId,
      'deviceName': device.userName,
      'isHost': device.isHost,
      'connectionType': device.deviceInfo?['connectionType'] ?? 'unknown',
      'port': device.deviceInfo?['port'],
    };

    // Try to connect via device ID
    service.connectToDevice(deviceMap);
  }

  Color _getSignalColor(int? level) {
    if (level == null) return Colors.grey;
    if (level > -50) return Colors.green;
    if (level > -70) return Colors.orange;
    return Colors.red;
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 30) return 'Now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool _isRecentlySeen(DateTime lastSeen) {
    return DateTime.now().difference(lastSeen).inMinutes < 5;
  }
}
