import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/gps_controller.dart';
import '../../pages/gps_page.dart';
import '../../utils/resqlink_theme.dart';

class GpsActionButtons extends StatelessWidget {
  final Function() onLocationDetailsRequest;
  final Function() onCenterCurrentLocation;

  const GpsActionButtons({
    super.key,
    required this.onLocationDetailsRequest,
    required this.onCenterCurrentLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GpsController>(
      builder: (context, controller, child) {
        // Set context in controller if not already set
        if (controller.context == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.setContext(context);
          });
        }

        return Positioned(
          top:
              MediaQuery.of(context).size.height *
              0.15, // Responsive positioning
          right: 16,
          child: SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildCurrentLocationButton(controller),
                    const SizedBox(height: 8),
                    _buildSaveLocationButton(controller),
                    const SizedBox(height: 8),
                    _buildLocationTypeButton(controller),
                    const SizedBox(height: 8),
                    _buildShareLocationButton(controller),
                    const SizedBox(height: 8),
                    _buildOfflineMapButton(controller),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentLocationButton(GpsController controller) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ResQLinkTheme.cardDark,
        border: Border.all(
          color: controller.isLocationServiceEnabled
              ? ResQLinkTheme.safeGreen
              : Colors.red,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: () {
          onCenterCurrentLocation();
          controller.getCurrentLocation();
        },
        icon: Icon(
          Icons.my_location,
          color: controller.isLocationServiceEnabled
              ? ResQLinkTheme.safeGreen
              : Colors.red,
          size: 24,
        ),
        tooltip: 'Center on current location',
      ),
    );
  }

  Widget _buildSaveLocationButton(GpsController controller) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ResQLinkTheme.cardDark,
        border: Border.all(color: ResQLinkTheme.locationBlue, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: controller.currentLocation != null
            ? () => _showSaveLocationDialog(controller)
            : null,
        icon: Icon(
          Icons.bookmark_add,
          color: controller.currentLocation != null
              ? ResQLinkTheme.locationBlue
              : Colors.grey,
          size: 24,
        ),
        tooltip: 'Save current location',
      ),
    );
  }

  Widget _buildLocationTypeButton(GpsController controller) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ResQLinkTheme.cardDark,
        border: Border.all(
          color: _getSelectedLocationTypeColor(controller.selectedLocationType),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: () => _showLocationTypeDialog(controller),
        icon: Icon(
          _getLocationTypeIcon(controller.selectedLocationType),
          color: _getSelectedLocationTypeColor(controller.selectedLocationType),
          size: 24,
        ),
        tooltip: 'Change location type',
      ),
    );
  }

  Widget _buildShareLocationButton(GpsController controller) {
    final bool canShare =
        controller.currentLocation != null &&
        controller.p2pService.connectedDevices.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ResQLinkTheme.cardDark,
        border: Border.all(
          color: canShare ? Colors.orange : Colors.grey,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        onPressed: canShare ? () => controller.shareCurrentLocation() : null,
        icon: Icon(
          Icons.share_location,
          color: canShare ? Colors.orange : Colors.grey,
          size: 24,
        ),
        tooltip: canShare
            ? 'Share location with connected devices'
            : 'No devices connected',
      ),
    );
  }

  Widget _buildOfflineMapButton(GpsController controller) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ResQLinkTheme.cardDark,
        border: Border.all(
          color: controller.hasOfflineMap
              ? ResQLinkTheme.safeGreen
              : Colors.purple,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          IconButton(
            onPressed: () => _showOfflineMapDialog(controller),
            icon: Icon(
              controller.hasOfflineMap ? Icons.offline_pin : Icons.download,
              color: controller.hasOfflineMap
                  ? ResQLinkTheme.safeGreen
                  : Colors.purple,
              size: 24,
            ),
            tooltip: controller.hasOfflineMap
                ? 'Offline maps available'
                : 'Download offline maps',
          ),
          // Status indicator dot
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: controller.hasOfflineMap
                    ? ResQLinkTheme.safeGreen
                    : Colors.red,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: controller.hasOfflineMap
                  ? Icon(Icons.check, size: 8, color: Colors.white)
                  : Icon(Icons.close, size: 8, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showSaveLocationDialog(GpsController controller) {
    final context = controller.context;
    if (context == null) return;

    String message = '';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: const Text(
          'Save Location',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Save current location as ${_getLocationTypeText(controller.selectedLocationType)}?',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => message = value,
              decoration: InputDecoration(
                hintText: 'Optional message...',
                hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.1),
              ),
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await controller.saveCurrentLocation(
                message: message.isNotEmpty ? message : null,
              );
              _showLocationSavedSnackbar(controller);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ResQLinkTheme.locationBlue,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showLocationTypeDialog(GpsController controller) {
    final context = controller.context;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: const Text(
          'Select Location Type',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: LocationType.values.length,
            itemBuilder: (context, index) {
              final type = LocationType.values[index];
              final isSelected = type == controller.selectedLocationType;
              final color = _getSelectedLocationTypeColor(type);

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.2) : null,
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: color, width: 2)
                      : null,
                ),
                child: ListTile(
                  leading: Icon(_getLocationTypeIcon(type), color: color),
                  title: Text(
                    _getLocationTypeText(type),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    controller.setSelectedLocationType(type);
                    Navigator.pop(dialogContext);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showOfflineMapDialog(GpsController controller) {
    final context = controller.context;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Row(
          children: [
            Icon(Icons.map, color: Colors.white, size: 24),
            const SizedBox(width: 8),
            const Text('Offline Maps', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: controller.hasOfflineMap
                    ? ResQLinkTheme.safeGreen.withValues(alpha: 0.1)
                    : Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: controller.hasOfflineMap
                      ? ResQLinkTheme.safeGreen
                      : Colors.purple,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  // Status Icon
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: controller.hasOfflineMap
                          ? ResQLinkTheme.safeGreen
                          : Colors.purple,
                    ),
                    child: Icon(
                      controller.hasOfflineMap
                          ? Icons.check_circle
                          : Icons.download_for_offline,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Status Text
                  Text(
                    controller.hasOfflineMap
                        ? 'Maps Installed'
                        : 'Maps Not Installed',
                    style: TextStyle(
                      color: controller.hasOfflineMap
                          ? ResQLinkTheme.safeGreen
                          : Colors.purple,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.hasOfflineMap
                        ? 'Offline maps are available for this area. You can navigate without internet connection.'
                        : 'Download offline maps for this area to use without internet connection.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Map Details Section
            if (controller.hasOfflineMap) ...[
              _buildMapDetailRow(
                icon: Icons.location_on,
                label: 'Coverage Area',
                value: 'Current Region',
                color: ResQLinkTheme.safeGreen,
              ),
              const SizedBox(height: 8),
              _buildMapDetailRow(
                icon: Icons.storage,
                label: 'Storage Used',
                value: '~50 MB', // You can get this from controller
                color: Colors.blue,
              ),
              const SizedBox(height: 8),
              _buildMapDetailRow(
                icon: Icons.update,
                label: 'Last Updated',
                value: '2 days ago', // You can get this from controller
                color: Colors.orange,
              ),
            ] else ...[
              _buildMapDetailRow(
                icon: Icons.download,
                label: 'Download Size',
                value: '~50 MB',
                color: Colors.purple,
              ),
              const SizedBox(height: 8),
              _buildMapDetailRow(
                icon: Icons.wifi_off,
                label: 'Offline Access',
                value: 'Available after download',
                color: Colors.grey,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: Colors.grey.withValues(alpha: 0.8)),
            ),
          ),
          if (controller.hasOfflineMap) ...[
            // Update button for installed maps
            TextButton(
              onPressed: () {
                controller.updateOfflineMap();
                Navigator.pop(context);
                _showMapUpdateSnackbar(controller);
              },
              child: Text('Update', style: TextStyle(color: Colors.orange)),
            ),
            // Delete button for installed maps
            TextButton(
              onPressed: () {
                _showDeleteMapConfirmation(controller, context);
              },
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ] else ...[
            // Download button for non-installed maps
            ElevatedButton.icon(
              onPressed: () {
                controller.downloadOfflineMap();
                Navigator.pop(context);
                _showMapDownloadSnackbar(controller);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.download, size: 20),
              label: const Text('Download'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMapDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
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
    );
  }

  void _showDeleteMapConfirmation(
    GpsController controller,
    BuildContext parentContext,
  ) {
    showDialog(
      context: parentContext,
      builder: (context) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Delete Offline Maps',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the offline maps? You will need to download them again to use offline navigation.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.deleteOfflineMap();
              Navigator.pop(context); // Close confirmation
              Navigator.pop(parentContext); // Close main dialog
              _showMapDeletedSnackbar(controller);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showMapDownloadSnackbar(GpsController controller) {
    final context = controller.context;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            const Text('Downloading offline maps...'),
          ],
        ),
        backgroundColor: Colors.purple,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showMapUpdateSnackbar(GpsController controller) {
    final context = controller.context;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.update, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Text('Updating offline maps...'),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showMapDeletedSnackbar(GpsController controller) {
    final context = controller.context;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.delete, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Text('Offline maps deleted'),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showLocationSavedSnackbar(GpsController controller) {
    final context = controller.context;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Location saved as ${_getLocationTypeText(controller.selectedLocationType)}',
        ),
        backgroundColor: ResQLinkTheme.safeGreen,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: onLocationDetailsRequest,
        ),
      ),
    );
  }

  Color _getSelectedLocationTypeColor(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return Colors.blue;
      case LocationType.emergency:
      case LocationType.sos:
        return ResQLinkTheme.primaryRed;
      case LocationType.safezone:
        return ResQLinkTheme.safeGreen;
      case LocationType.hazard:
        return Colors.orange;
      case LocationType.evacuationPoint:
        return Colors.purple;
      case LocationType.medicalAid:
        return Colors.red;
      case LocationType.supplies:
        return Colors.cyan;
    }
  }

  IconData _getLocationTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return Icons.location_on;
      case LocationType.emergency:
      case LocationType.sos:
        return Icons.emergency;
      case LocationType.safezone:
        return Icons.shield;
      case LocationType.hazard:
        return Icons.warning;
      case LocationType.evacuationPoint:
        return Icons.exit_to_app;
      case LocationType.medicalAid:
        return Icons.medical_services;
      case LocationType.supplies:
        return Icons.inventory;
    }
  }

  String _getLocationTypeText(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return 'Current Location';
      case LocationType.emergency:
        return 'Emergency Location';
      case LocationType.sos:
        return 'SOS Location';
      case LocationType.safezone:
        return 'Safe Zone';
      case LocationType.hazard:
        return 'Hazard Area';
      case LocationType.evacuationPoint:
        return 'Evacuation Point';
      case LocationType.medicalAid:
        return 'Medical Aid';
      case LocationType.supplies:
        return 'Supplies';
    }
  }
}
