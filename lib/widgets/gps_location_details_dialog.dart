import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../gps_page.dart';
import '../utils/resqlink_theme.dart';

class GpsLocationDetailsDialog extends StatelessWidget {
  final LocationModel location;
  final Function(LocationModel)? onLocationShare;
  final VoidCallback? onClose;

  const GpsLocationDetailsDialog({
    super.key,
    required this.location,
    this.onLocationShare,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        decoration: BoxDecoration(
          color: ResQLinkTheme.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _getLocationTypeColor(location.type).withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildContent(),
              ),
            ),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final Color typeColor = _getLocationTypeColor(location.type);
    final IconData typeIcon = _getLocationTypeIcon(location.type);
    final bool isEmergency = location.type == LocationType.emergency || 
                           location.type == LocationType.sos;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
        border: Border(
          bottom: BorderSide(
            color: typeColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: typeColor, width: 2),
            ),
            child: Icon(
              typeIcon,
              color: typeColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getLocationTypeText(location.type),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.grey.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDateTime(location.timestamp),
                      style: TextStyle(
                        color: Colors.grey.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isEmergency)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ResQLinkTheme.primaryRed,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'EMERGENCY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCoordinatesSection(),
        const SizedBox(height: 24),
        _buildLocationInfoSection(),
        if (location.message != null) ...[
          const SizedBox(height: 24),
          _buildMessageSection(),
        ],
        if (location.emergencyLevel != null) ...[
          const SizedBox(height: 24),
          _buildEmergencyLevelSection(),
        ],
        if (location.batteryLevel != null) ...[
          const SizedBox(height: 24),
          _buildBatterySection(),
        ],
      ],
    );
  }

  Widget _buildCoordinatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Coordinates',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildCoordinateItem(
          'Latitude',
          location.latitude.toStringAsFixed(6),
          Icons.north,
        ),
        const SizedBox(height: 8),
        _buildCoordinateItem(
          'Longitude',
          location.longitude.toStringAsFixed(6),
          Icons.east,
        ),
      ],
    );
  }

  Widget _buildCoordinateItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: ResQLinkTheme.locationBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _copyToClipboard(value),
            icon: Icon(
              Icons.copy,
              color: Colors.grey.withValues(alpha: 0.6),
              size: 20,
            ),
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Location Information',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoItem(
          'Timestamp',
          location.timestamp.toString().substring(0, 19),
          Icons.schedule,
        ),
        const SizedBox(height: 8),
        _buildInfoItem(
          'Sync Status',
          location.synced ? 'Synced' : 'Not Synced',
          location.synced ? Icons.cloud_done : Icons.cloud_off,
          color: location.synced ? ResQLinkTheme.safeGreen : Colors.orange,
        ),
        if (location.userId != null) ...[
          const SizedBox(height: 8),
          _buildInfoItem(
            'User ID',
            location.userId!,
            Icons.person,
          ),
        ],
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon, {Color? color}) {
    final itemColor = color ?? ResQLinkTheme.locationBlue;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: itemColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: itemColor, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Message',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.message, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  location.message!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyLevelSection() {
    final emergencyColor = _getEmergencyLevelColor(location.emergencyLevel!);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Emergency Level',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: emergencyColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: emergencyColor, width: 2),
          ),
          child: Row(
            children: [
              Icon(
                _getEmergencyLevelIcon(location.emergencyLevel!),
                color: emergencyColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                _getEmergencyLevelText(location.emergencyLevel!),
                style: TextStyle(
                  color: emergencyColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBatterySection() {
    final batteryColor = _getBatteryColor(location.batteryLevel!);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Battery Level',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: batteryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: batteryColor.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.battery_std, color: batteryColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${location.batteryLevel}%',
                      style: TextStyle(
                        color: batteryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: location.batteryLevel! / 100,
                      backgroundColor: Colors.grey.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(batteryColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.grey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              label: const Text('Close'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (onLocationShare != null)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  onLocationShare!(location);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.share),
                label: const Text('Share'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  // Helper methods
  Color _getLocationTypeColor(LocationType type) {
    switch (type) {
      case LocationType.normal: return Colors.blue;
      case LocationType.emergency:
      case LocationType.sos: return ResQLinkTheme.primaryRed;
      case LocationType.safezone: return ResQLinkTheme.safeGreen;
      case LocationType.hazard: return Colors.orange;
      case LocationType.evacuationPoint: return Colors.purple;
      case LocationType.medicalAid: return Colors.red;
      case LocationType.supplies: return Colors.cyan;
    }
  }

  IconData _getLocationTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.normal: return Icons.location_on;
      case LocationType.emergency:
      case LocationType.sos: return Icons.emergency;
      case LocationType.safezone: return Icons.shield;
      case LocationType.hazard: return Icons.warning;
      case LocationType.evacuationPoint: return Icons.exit_to_app;
      case LocationType.medicalAid: return Icons.medical_services;
      case LocationType.supplies: return Icons.inventory;
    }
  }

  String _getLocationTypeText(LocationType type) {
    switch (type) {
      case LocationType.normal: return 'Current Location';
      case LocationType.emergency: return 'Emergency Location';
      case LocationType.sos: return 'SOS Location';
      case LocationType.safezone: return 'Safe Zone';
      case LocationType.hazard: return 'Hazard Area';
      case LocationType.evacuationPoint: return 'Evacuation Point';
      case LocationType.medicalAid: return 'Medical Aid';
      case LocationType.supplies: return 'Supplies';
    }
  }

  Color _getEmergencyLevelColor(EmergencyLevel level) {
    switch (level) {
      case EmergencyLevel.safe: return ResQLinkTheme.safeGreen;
      case EmergencyLevel.caution: return Colors.yellow;
      case EmergencyLevel.warning: return Colors.orange;
      case EmergencyLevel.danger: return ResQLinkTheme.emergencyOrange;
      case EmergencyLevel.critical: return ResQLinkTheme.primaryRed;
    }
  }

  IconData _getEmergencyLevelIcon(EmergencyLevel level) {
    switch (level) {
      case EmergencyLevel.safe: return Icons.check_circle;
      case EmergencyLevel.caution: return Icons.info;
      case EmergencyLevel.warning: return Icons.warning_amber;
      case EmergencyLevel.danger: return Icons.warning;
      case EmergencyLevel.critical: return Icons.emergency;
    }
  }

  String _getEmergencyLevelText(EmergencyLevel level) {
    switch (level) {
      case EmergencyLevel.safe: return 'All Clear';
      case EmergencyLevel.caution: return 'Stay Alert';
      case EmergencyLevel.warning: return 'Warning Level';
      case EmergencyLevel.danger: return 'Danger Zone';
      case EmergencyLevel.critical: return 'CRITICAL EMERGENCY';
    }
  }

  Color _getBatteryColor(int level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
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
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}