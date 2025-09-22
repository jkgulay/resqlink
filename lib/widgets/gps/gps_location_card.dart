import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/gps_controller.dart';
import '../../pages/gps_page.dart';
import '../../utils/resqlink_theme.dart';

class GpsLocationList extends StatefulWidget {
  final Function(LocationModel) onLocationSelected;
  final Function(LocationModel) onLocationShare;

  const GpsLocationList({
    super.key,
    required this.onLocationSelected,
    required this.onLocationShare,
  });

  @override
  State<GpsLocationList> createState() => _GpsLocationListState();
}

class _GpsLocationListState extends State<GpsLocationList>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
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
        if (controller.context == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            controller.setContext(context);
          });
        }

        final screenHeight = MediaQuery.of(context).size.height;
        final maxHeight = screenHeight * 0.4; // Max 40% of screen height

        return Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, (1 - _slideAnimation.value) * 200),
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: _isExpanded ? maxHeight : 80,
                      minHeight: 80,
                    ),
                    decoration: BoxDecoration(
                      color: ResQLinkTheme.cardDark.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: ResQLinkTheme.locationBlue.withValues(
                          alpha: 0.3,
                        ),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCompactHeader(controller),
                        if (_isExpanded)
                          Expanded(
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: controller.savedLocations.isEmpty
                                  ? _buildEmptyContent()
                                  : _buildLocationsList(controller),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactHeader(GpsController controller) {
    return GestureDetector(
      onTap: _toggleExpansion,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: _isExpanded
              ? Border(
                  bottom: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.3),
                    width: 1,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ResQLinkTheme.locationBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.bookmark,
                color: ResQLinkTheme.locationBlue,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Saved Locations',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: ResQLinkTheme.locationBlue.withValues(
                            alpha: 0.2,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: ResQLinkTheme.locationBlue.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Text(
                          '${controller.savedLocations.length}',
                          style: TextStyle(
                            color: ResQLinkTheme.locationBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_isExpanded) ...[
                    const SizedBox(height: 2),
                    Text(
                      controller.savedLocations.isEmpty
                          ? 'Tap to see locations'
                          : 'Latest: ${_getLatestLocationText(controller)}',
                      style: TextStyle(
                        color: Colors.grey.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (controller.savedLocations.isNotEmpty && !_isExpanded)
              _buildQuickActionButtons(controller),
            AnimatedRotation(
              turns: _isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.keyboard_arrow_up,
                color: Colors.white.withValues(alpha: 0.7),
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButtons(GpsController controller) {
    final latestLocation = controller.savedLocations.isNotEmpty
        ? controller.savedLocations.last
        : null;

    if (latestLocation == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => widget.onLocationSelected(latestLocation),
          icon: const Icon(Icons.location_on, size: 16),
          iconSize: 16,
          color: ResQLinkTheme.locationBlue,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Go to location',
        ),
        IconButton(
          onPressed: () => widget.onLocationShare(latestLocation),
          icon: const Icon(Icons.share, size: 16),
          iconSize: 16,
          color: ResQLinkTheme.locationBlue,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Share location',
        ),
      ],
    );
  }

  String _getLatestLocationText(GpsController controller) {
    if (controller.savedLocations.isEmpty) return '';

    final latest = controller.savedLocations.last;
    final timeAgo = _formatDateTime(latest.timestamp);
    return '${_getLocationTypeText(latest.type)} • $timeAgo';
  }

  Widget _buildEmptyContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 32,
            color: Colors.grey.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'No saved locations',
            style: TextStyle(
              color: Colors.grey.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Save your current location to see it here',
            style: TextStyle(
              color: Colors.grey.withValues(alpha: 0.6),
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationsList(GpsController controller) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: controller.savedLocations.length,
      itemBuilder: (context, index) {
        final location = controller
            .savedLocations[controller.savedLocations.length - 1 - index];
        return _buildCompactLocationItem(location, controller);
      },
    );
  }

  Widget _buildCompactLocationItem(
    LocationModel location,
    GpsController controller,
  ) {
    final Color typeColor = _getLocationTypeColor(location.type);
    final IconData typeIcon = _getLocationTypeIcon(location.type);
    final bool isEmergency =
        location.type == LocationType.emergency ||
        location.type == LocationType.sos;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: typeColor.withValues(alpha: 0.3),
          width: isEmergency ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: typeColor, width: 1),
          ),
          child: Icon(typeIcon, color: typeColor, size: 14),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _getLocationTypeText(location.type),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
            if (isEmergency)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ResQLinkTheme.primaryRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'EMR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Icon(Icons.access_time, size: 10, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _formatDateTime(location.timestamp),
                style: TextStyle(
                  color: Colors.grey.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => widget.onLocationShare(location),
              icon: const Icon(Icons.share, size: 14),
              iconSize: 14,
              color: ResQLinkTheme.locationBlue,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Share',
            ),
            IconButton(
              onPressed: () =>
                  _showDeleteLocationDialog(location, controller, context),
              icon: const Icon(Icons.delete, size: 14),
              iconSize: 14,
              color: Colors.red.withValues(alpha: 0.8),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Delete',
            ),
          ],
        ),
        onTap: () => widget.onLocationSelected(location),
      ),
    );
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

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showDeleteLocationDialog(
    LocationModel location,
    GpsController controller,
    BuildContext context,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ResQLinkTheme.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Location',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          'Remove this saved location?',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              controller.deleteLocation(location);
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
