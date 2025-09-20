import 'package:flutter/material.dart';

class DeviceBadges {
  static Widget buildConnectionStatusBadge(bool isConnected, String deviceStatus) {
    if (!isConnected) return SizedBox.shrink();

    Color badgeColor;
    String badgeText;

    if (deviceStatus == 'connected') {
      badgeColor = Colors.green;
      badgeText = 'CONNECTED';
    } else {
      badgeColor = Colors.orange;
      badgeText = 'LINKED';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        badgeText,
        style: TextStyle(
          fontSize: 10,
          color: badgeColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static Widget buildConnectionTypeBadge(String connectionType) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: getConnectionTypeColor(connectionType).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: getConnectionTypeColor(connectionType).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        getConnectionTypeLabel(connectionType),
        style: TextStyle(
          fontSize: 10,
          color: getConnectionTypeColor(connectionType),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Widget buildSignalBadge(Map<String, dynamic> device) {
    final signalStrength = parseSignalStrength(device);
    final signalLevel = getSignalLevel(signalStrength);
    final signalColor = getSignalColor(signalLevel);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: signalColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: signalColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildSignalBars(signalLevel, signalColor),
          SizedBox(width: 4),
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
    );
  }

  static Widget buildSignalBars(int level, Color color) {
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

  static int parseSignalStrength(Map<String, dynamic> device) {
    if (device['signalLevel'] != null) return device['signalLevel'] as int;
    if (device['rssi'] != null) return device['rssi'] as int;
    if (device['level'] != null) return device['level'] as int;

    final connectionType = device['connectionType'] as String? ?? 'unknown';
    switch (connectionType) {
      case 'wifi_direct': return -45;
      case 'hotspot': return -55;
      default: return -65;
    }
  }

  static int getSignalLevel(int dbm) {
    if (dbm >= -50) return 5;
    if (dbm >= -60) return 4;
    if (dbm >= -70) return 3;
    if (dbm >= -80) return 2;
    if (dbm >= -90) return 1;
    return 0;
  }

  static Color getSignalColor(int level) {
    switch (level) {
      case 5:
      case 4: return Colors.green;
      case 3: return Colors.amber;
      case 2:
      case 1: return Colors.orange;
      default: return Colors.red;
    }
  }

  static IconData getConnectionTypeIcon(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'wifi_direct': return Icons.wifi;
      case 'hotspot':
      case 'hotspot_enhanced': return Icons.router;
      case 'mdns':
      case 'mdns_enhanced': return Icons.broadcast_on_personal;
      default: return Icons.devices;
    }
  }

  static Color getConnectionTypeColor(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'wifi_direct': return Colors.blue;
      case 'hotspot':
      case 'hotspot_enhanced': return Colors.purple;
      case 'mdns':
      case 'mdns_enhanced': return Colors.orange;
      default: return Colors.grey;
    }
  }

  static String getConnectionTypeLabel(String connectionType) {
    switch (connectionType.toLowerCase()) {
      case 'wifi_direct': return 'WiFi Direct';
      case 'hotspot': return 'Hotspot';
      case 'hotspot_enhanced': return 'Hotspot+';
      case 'mdns': return 'mDNS';
      case 'mdns_enhanced': return 'mDNS+';
      default: return 'Unknown';
    }
  }
}