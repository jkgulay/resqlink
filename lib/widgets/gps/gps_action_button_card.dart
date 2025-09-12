import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/gps_controller.dart';
import '../../pages/gps_page.dart';
import '../../utils/resqlink_theme.dart';

class GpsActionButtons extends StatefulWidget {
  final Function() onCenterCurrentLocation;

  const GpsActionButtons({
    super.key,
    required this.onCenterCurrentLocation,
  });

  @override
  State<GpsActionButtons> createState() => _GpsActionButtonsState();
}

class _GpsActionButtonsState extends State<GpsActionButtons>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpansion() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GpsController>(
      builder: (context, controller, child) {
        return Positioned(
          right: 16,
          top: 120, // Below the stats panel
          child: SafeArea(
            child: Column(
              children: [
                // Main action button (always visible)
                _buildMainActionButton(controller),
                
                // Expandable buttons
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildActionButton(
                        icon: Icons.my_location,
                        onPressed: widget.onCenterCurrentLocation,
                        tooltip: 'Center on location',
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 8),
                      _buildActionButton(
                        icon: Icons.download,
                        onPressed: () => controller.downloadOfflineMap(),
                        tooltip: 'Download offline map',
                        color: Colors.green,
                        isLoading: controller.isDownloadingMaps,
                      ),
                      const SizedBox(height: 8),
                      _buildActionButton(
                        icon: Icons.save,
                        onPressed: () => _showSaveLocationDialog(controller),
                        tooltip: 'Save current location',
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      _buildActionButton(
                        icon: Icons.share,
                        onPressed: () => controller.shareCurrentLocation(),
                        tooltip: 'Share location',
                        color: Colors.purple,
                      ),
                      const SizedBox(height: 8),
                      _buildActionButton(
                        icon: Icons.location_searching,
                        onPressed: () => controller.getCurrentLocation(),
                        tooltip: 'Get current location',
                        color: Colors.teal,
                        isLoading: controller.isLoading,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainActionButton(GpsController controller) {
    return FloatingActionButton(
      onPressed: _toggleExpansion,
      backgroundColor: ResQLinkTheme.cardDark,
      foregroundColor: Colors.white,
      elevation: 8,
      child: AnimatedRotation(
        turns: _isExpanded ? 0.125 : 0, // 45 degree rotation when expanded
        duration: const Duration(milliseconds: 300),
        child: Icon(
          _isExpanded ? Icons.close : Icons.menu,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    required Color color,
    bool isLoading = false,
  }) {
    return FloatingActionButton(
      mini: true,
      onPressed: isLoading ? null : onPressed,
      backgroundColor: color.withValues(alpha: 0.9),
      foregroundColor: Colors.white,
      tooltip: tooltip,
      elevation: 4,
      child: isLoading 
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(icon, size: 20),
    );
  }

  void _showSaveLocationDialog(GpsController controller) {
    String message = '';
    LocationType selectedType = LocationType.normal;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ResQLinkTheme.cardDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Save Location',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Location Type:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<LocationType>(
                value: selectedType,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                dropdownColor: ResQLinkTheme.cardDark,
                style: const TextStyle(color: Colors.white),
                onChanged: (LocationType? newValue) {
                  if (newValue != null) {
                    setDialogState(() {
                      selectedType = newValue;
                    });
                  }
                },
                items: LocationType.values.map((LocationType type) {
                  return DropdownMenuItem<LocationType>(
                    value: type,
                    child: Row(
                      children: [
                        Icon(
                          _getLocationTypeIcon(type),
                          color: _getLocationTypeColor(type),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getLocationTypeText(type),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Message (optional):',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => message = value,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add a note about this location...',
                  hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: Colors.grey.withValues(alpha: 0.2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                controller.setSelectedLocationType(selectedType);
                controller.saveCurrentLocation(message: message.isEmpty ? null : message);
                Navigator.pop(context);
                
                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Location saved as ${_getLocationTypeText(selectedType)}'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods for location types
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

  Color _getLocationTypeColor(LocationType type) {
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

  String _getLocationTypeText(LocationType type) {
    switch (type) {
      case LocationType.normal:
        return 'Normal Location';
      case LocationType.emergency:
        return 'Emergency';
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
        return 'Supply Point';
    }
  }
}